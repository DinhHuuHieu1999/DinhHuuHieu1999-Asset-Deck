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
import { AssetExportV4Repository } from './asset-export-v4.repository';
import { buildAssetExportV4 } from './asset-export-v4';

/** Location-aware export exists only inside the explicitly enabled v4 capability. */
@Auth()
@Controller('assets/export/v4')
export class AssetExportV4Controller {
  constructor(private readonly repository: AssetExportV4Repository) {}

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
    return buildAssetExportV4(await this.repository.exportSnapshot(owner));
  }
}
