import { assetWarrantyWindow } from './asset-warranty';
import { isAssetDatesEnabled } from './asset-dates.config';
import {
  BadRequestException,
  Body,
  ConflictException,
  Controller,
  Get,
  Header,
  NotFoundException,
  Param,
  ParseUUIDPipe,
  Put,
  Query,
  Req,
  UnauthorizedException,
} from '@nestjs/common';
import { IsIn, IsString, MaxLength } from 'class-validator';
import { Auth } from '../../shared/decorators/auth.decorator';
import { isAccountId } from '../auth/account.repository';
import {
  normalizeAssetLocation,
  validateAssetLocationUpdate,
} from './asset-location';
import { AssetLocationRepository } from './asset-location.repository';
import { AssetQueryDto } from './assets.dto';

/** Location filtering is explicit; unknown is not equivalent to no filter. */
export class AssetLocationQueryDto extends AssetQueryDto {
  @IsIn(['all', 'unknown', 'exact'])
  locationMode: 'all' | 'unknown' | 'exact' = 'all';
  @IsString()
  @MaxLength(120)
  location = '';
  @IsIn(['', 'expired', 'expiring_soon'])
  warranty = '';
  @IsString()
  @MaxLength(10)
  asOf = '';
}
type OwnerRequest = { user?: { userId?: string } };
function owner(req: OwnerRequest): string {
  if (!req.user?.userId || !isAccountId(req.user.userId))
    throw new UnauthorizedException();
  return req.user.userId;
}
function noQuery(query: Record<string, unknown>): void {
  if (Object.keys(query).length)
    throw new BadRequestException(
      'Location edits do not accept query parameters',
    );
}

/** Authenticated opt-in routes; no location permissions or automatic discovery. */
@Auth()
@Controller('assets')
export class AssetLocationController {
  constructor(private readonly repository: AssetLocationRepository) {}

  /** List an owner-scoped location-filtered inventory before pagination. */
  @Get('locations/inventory')
  @Header('Cache-Control', 'no-store')
  async list(@Req() req: OwnerRequest, @Query() query: AssetLocationQueryDto) {
    const account = owner(req);
    if (query.locationMode !== 'exact' && query.location !== '') {
      throw new BadRequestException(
        'Location label requires exact filter mode',
      );
    }
    const location =
      query.locationMode === 'exact'
        ? normalizeAssetLocation(query.location)
        : null;
    if (!query.warranty && query.asOf)
      throw new BadRequestException('Reference date requires warranty filter');
    if (query.warranty && !isAssetDatesEnabled())
      throw new BadRequestException('Warranty filtering is unavailable');
    const window = query.warranty
      ? assetWarrantyWindow(query.warranty, query.asOf)
      : undefined;
    return this.repository.list(
      account,
      query,
      {
        mode: query.locationMode,
        location,
      },
      window,
    );
  }

  /** Read location and the shared asset version without revealing other owners. */
  @Get(':id/location')
  @Header('Cache-Control', 'no-store')
  async read(
    @Req() req: OwnerRequest,
    @Param('id', new ParseUUIDPipe()) id: string,
    @Query() query: Record<string, unknown>,
  ) {
    const account = owner(req);
    noQuery(query);
    const result = await this.repository.read(account, id);
    if (!result) throw new NotFoundException('Asset is unavailable');
    return result;
  }

  /** Explicit replacement never retries or silently overwrites stale versions. */
  @Put(':id/location')
  @Header('Cache-Control', 'no-store')
  async update(
    @Req() req: OwnerRequest,
    @Param('id', new ParseUUIDPipe()) id: string,
    @Body() input: unknown,
    @Query() query: Record<string, unknown>,
  ) {
    const account = owner(req);
    noQuery(query);
    const result = await this.repository.update(
      account,
      id,
      validateAssetLocationUpdate(input),
    );
    if (!result)
      throw new ConflictException(
        'Asset changed or is unavailable; reload before editing location',
      );
    return result;
  }
}
