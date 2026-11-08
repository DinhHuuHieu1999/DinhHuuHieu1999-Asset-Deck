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
import { AssetDatesRepository } from './asset-dates.repository';
import { buildAssetExportV2 } from './asset-export-v2';

/** Date-aware export exists only inside the explicitly enabled dates capability. */
@Auth()
@Controller('assets/export/v2')
export class AssetExportV2Controller {
  constructor(private readonly repository: AssetDatesRepository) {}

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
    return buildAssetExportV2(await this.repository.exportSnapshot(owner));
  }
}
