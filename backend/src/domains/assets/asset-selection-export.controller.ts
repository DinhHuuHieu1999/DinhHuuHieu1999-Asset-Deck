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
import { assetWarrantyWindow } from './asset-warranty';
import {
  buildAssetSelectionExport,
  validateAssetSelectionScope,
  type AssetSelectionScope,
} from './asset-selection-export';
import { AssetSelectionExportRepository } from './asset-selection-export.repository';

/** Parse an explicit selection; reject paging, unknown keys and non-scalar queries. */
export function assetSelectionQuery(
  query: Record<string, unknown>,
): AssetSelectionScope {
  const allowed = [
    'q',
    'status',
    'category',
    'locationMode',
    'location',
    'sort',
    'warranty',
    'asOf',
  ];
  if (
    Object.keys(query).some(
      (key) => !allowed.includes(key) || typeof query[key] !== 'string',
    )
  ) {
    throw new BadRequestException('Invalid selection query');
  }
  const value = (key: string, fallback = '') =>
    (query[key] as string) ?? fallback;
  const mode = value('locationMode', 'all');
  const label = value('location');
  const warranty = value('warranty');
  const asOf = value('asOf');
  if (
    (mode !== 'exact' && label !== '') ||
    (!warranty && asOf) ||
    (warranty && !asOf)
  ) {
    throw new BadRequestException('Inconsistent selection filters');
  }
  return validateAssetSelectionScope({
    q: value('q').trim(),
    status: value('status'),
    category: value('category').trim(),
    locationMode: mode,
    location: mode === 'exact' ? label.trim() : null,
    sort: value('sort', 'updated_desc'),
    warranty: warranty ? assetWarrantyWindow(warranty, asOf) : null,
  } as AssetSelectionScope);
}

/** Separate authenticated read-only route; registration remains opt-in. */
@Auth()
@Controller('assets/export/selection')
export class AssetSelectionExportController {
  constructor(private readonly repository: AssetSelectionExportRepository) {}
  /** Export every matching owner row from a single statement snapshot. */
  @Get()
  @Header('Cache-Control', 'no-store')
  async exportSelection(
    @Req() request: { user?: { userId?: string } },
    @Query() query: Record<string, unknown>,
  ) {
    const owner = request.user?.userId;
    if (!owner || !isAccountId(owner)) throw new UnauthorizedException();
    const scope = assetSelectionQuery(query);
    return buildAssetSelectionExport(
      await this.repository.exportSnapshot(owner, scope),
      scope,
    );
  }
}
