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
import { assetSelectionQuery } from './asset-selection-export.controller';
import {
  buildAssetSelectionExportV2,
  validateSelectionCheck,
  type AssetSelectionScopeV2,
} from './asset-selection-export-v2';
import { AssetSelectionExportV2Repository } from './asset-selection-export-v2.repository';

/** Parse explicit v2 check predicates without changing the strict v1 query parser. */
export function assetSelectionV2Query(
  query: Record<string, unknown>,
): AssetSelectionScopeV2 {
  const { checkMode, checkCutoff, ...base } = query;
  if (
    typeof checkMode !== 'string' ||
    (checkCutoff !== undefined && typeof checkCutoff !== 'string')
  )
    throw new BadRequestException('Invalid selection check query');
  const check = validateSelectionCheck(
    checkCutoff === undefined
      ? { mode: checkMode }
      : { mode: checkMode, cutoff: checkCutoff },
  );
  return { ...assetSelectionQuery(base), check };
}

/** Separate authenticated read-only route; registration remains opt-in. */
@Auth()
@Controller('assets/export/selection-v2')
export class AssetSelectionExportV2Controller {
  constructor(private readonly repository: AssetSelectionExportV2Repository) {}
  /** Export every matching owner row from a single statement snapshot. */
  @Get()
  @Header('Cache-Control', 'no-store')
  async exportSelection(
    @Req() request: { user?: { userId?: string } },
    @Query() query: Record<string, unknown>,
  ) {
    const owner = request.user?.userId;
    if (!owner || !isAccountId(owner)) throw new UnauthorizedException();
    const scope = assetSelectionV2Query(query);
    return buildAssetSelectionExportV2(
      await this.repository.exportSnapshot(owner, scope),
      scope,
    );
  }
}
