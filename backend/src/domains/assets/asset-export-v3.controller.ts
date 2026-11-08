import {
  BadRequestException,
  Controller,
  Get,
  Header,
  Query,
  Req,
  UnauthorizedException,
} from '@nestjs/common';
import { Auth } from '../../shared/decorators/auth.decorator';
import { isAccountId } from '../auth/account.repository';
import { AssetExportV3Repository } from './asset-export-v3.repository';
import { buildAssetExportV3 } from './asset-export-v3';

/** Location-aware export exists only inside the explicitly enabled v3 capability. */
@Auth()
@Controller('assets/export/v3')
export class AssetExportV3Controller {
  constructor(private readonly repository: AssetExportV3Repository) {}

  /** Export the authenticated owner's complete inventory, never a filtered page. */
  @Get()
  @Header('Cache-Control', 'no-store')
  async exportInventory(
    @Req() request: { user?: { userId?: string } },
    @Query() query: Record<string, unknown>,
  ) {
    const owner = request.user?.userId;
    if (!owner || !isAccountId(owner)) throw new UnauthorizedException();
    if (Object.keys(query).length)
      throw new BadRequestException('Export does not accept query parameters');
    return buildAssetExportV3(await this.repository.exportSnapshot(owner));
  }
}
