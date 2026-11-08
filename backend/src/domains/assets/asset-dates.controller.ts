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
import { Auth } from '../../shared/decorators/auth.decorator';
import { isAccountId } from '../auth/account.repository';
import { validateAssetDatesUpdate } from './asset-dates';
import { AssetDatesRepository } from './asset-dates.repository';

type OwnerRequest = { user?: { userId?: string } };
function owner(req: OwnerRequest, query: Record<string, unknown>): string {
  if (!req.user?.userId || !isAccountId(req.user.userId))
    throw new UnauthorizedException();
  if (Object.keys(query).length)
    throw new BadRequestException(
      'Date operations do not accept query parameters',
    );
  return req.user.userId;
}

/** Opt-in authenticated date routes; no owner or implicit partial replacement input. */
@Auth()
@Controller('assets/:id/dates')
export class AssetDatesController {
  constructor(private readonly repository: AssetDatesRepository) {}

  /** Return only the current owner's dates and shared edit version. */
  @Get()
  @Header('Cache-Control', 'no-store')
  async read(
    @Req() req: OwnerRequest,
    @Param('id', new ParseUUIDPipe()) id: string,
    @Query() query: Record<string, unknown>,
  ) {
    const result = await this.repository.read(owner(req, query), id);
    if (!result) throw new NotFoundException('Asset is unavailable');
    return result;
  }

  /** Explicit date replacement rejects stale edits and preserves unrelated fields. */
  @Put()
  @Header('Cache-Control', 'no-store')
  async update(
    @Req() req: OwnerRequest,
    @Param('id', new ParseUUIDPipe()) id: string,
    @Body() input: unknown,
    @Query() query: Record<string, unknown>,
  ) {
    const account = owner(req, query);
    const result = await this.repository.update(
      account,
      id,
      validateAssetDatesUpdate(input),
    );
    if (!result)
      throw new ConflictException(
        'Asset changed or is unavailable; reload before editing dates',
      );
    return result;
  }
}
