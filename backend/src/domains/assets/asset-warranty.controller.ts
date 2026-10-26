import {
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
import { assetWarrantyWindow } from './asset-warranty';
import { AssetWarrantyQueryDto } from './asset-warranty.dto';

/** Owner-scoped warranty list exists only inside the dates capability. */
@Auth()
@Controller('assets/warranty')
export class AssetWarrantyController {
  constructor(private readonly repository: AssetDatesRepository) {}

  /** Intersect warranty/search/status/category before pagination with a stable date. */
  @Get()
  @Header('Cache-Control', 'no-store')
  list(
    @Req() request: { user?: { userId?: string } },
    @Query() query: AssetWarrantyQueryDto,
  ) {
    const owner = request.user?.userId;
    if (!owner || !isAccountId(owner)) throw new UnauthorizedException();
    const window = assetWarrantyWindow(query.warranty, query.asOf);
    return this.repository.warrantyList(owner, query, window);
  }
}
