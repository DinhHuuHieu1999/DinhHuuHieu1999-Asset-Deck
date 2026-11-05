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
import { isAssetCalendarDate } from './asset-dates';
import { validateAssetCheckUpdate } from './asset-check';
import { AssetCheckRepository } from './asset-check.repository';

type OwnerRequest = { user?: { userId?: string } };
function account(req: OwnerRequest, query: Record<string, unknown>): string {
  if (!req.user?.userId || !isAccountId(req.user.userId))
    throw new UnauthorizedException();
  if (Object.keys(query).length)
    throw new BadRequestException('Check dates do not accept query parameters');
  return req.user.userId;
}

/** Explicit authenticated check-date access; no device discovery or automatic writes. */
@Auth()
@Controller('assets')
export class AssetCheckController {
  constructor(private readonly repository: AssetCheckRepository) {}

  /** Complete owner-only counts at an explicit calendar cutoff; no side effects. */
  @Get('check-overview/counts')
  @Header('Cache-Control', 'no-store')
  async overview(
    @Req() req: OwnerRequest,
    @Query() query: Record<string, unknown>,
  ) {
    const owner = account(req, {});
    if (
      Object.keys(query).length !== 1 ||
      !Object.hasOwn(query, 'cutoff') ||
      !isAssetCalendarDate(query.cutoff)
    ) {
      throw new BadRequestException('Expected a calendar cutoff only');
    }
    return this.repository.overview(owner, query.cutoff as string);
  }

  /** Read a manual calendar date without revealing another account's asset. */
  @Get(':id/check-date')
  @Header('Cache-Control', 'no-store')
  async read(
    @Req() req: OwnerRequest,
    @Param('id', new ParseUUIDPipe()) id: string,
    @Query() query: Record<string, unknown>,
  ) {
    const result = await this.repository.read(account(req, query), id);
    if (!result) throw new NotFoundException('Asset is unavailable');
    return result;
  }

  /** Require explicit clear/date and version; stale and unavailable writes are alike. */
  @Put(':id/check-date')
  @Header('Cache-Control', 'no-store')
  async update(
    @Req() req: OwnerRequest,
    @Param('id', new ParseUUIDPipe()) id: string,
    @Body() input: unknown,
    @Query() query: Record<string, unknown>,
  ) {
    const owner = account(req, query);
    const result = await this.repository.update(
      owner,
      id,
      validateAssetCheckUpdate(input),
    );
    if (!result)
      throw new ConflictException(
        'Asset changed or is unavailable; reload before editing check date',
      );
    return result;
  }
}
