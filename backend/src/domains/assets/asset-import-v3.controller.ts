// Adapted from the ToolDeck opt-in import source contract.
import {
  BadRequestException,
  Body,
  Controller,
  Header,
  HttpCode,
  Post,
  Query,
  Req,
  UnauthorizedException,
} from '@nestjs/common';
import type { Request } from 'express';
import { Auth } from '../../shared/decorators/auth.decorator';
import { isAccountId } from '../auth/account.repository';
import { AssetImportV3Repository } from './asset-import-v3.repository';

/** Separately opt-in write route; ownership comes only from authentication. */
@Auth()
@Controller('assets/import/v3')
export class AssetImportV3Controller {
  constructor(private readonly repository: AssetImportV3Repository) {}

  /** Explicit add-only operation; owner never comes from the request payload. */
  @Post()
  @HttpCode(200)
  @Header('Cache-Control', 'no-store')
  importBatch(
    @Req() req: Request & { user?: { userId?: string } },
    @Body() input: unknown,
    @Query() query: Record<string, unknown>,
  ) {
    const owner = req.user?.userId;
    if (!owner || !isAccountId(owner)) throw new UnauthorizedException();
    if (Object.keys(query).length)
      throw new BadRequestException('Import does not accept query parameters');
    return this.repository.importBatch(owner, input);
  }
}
