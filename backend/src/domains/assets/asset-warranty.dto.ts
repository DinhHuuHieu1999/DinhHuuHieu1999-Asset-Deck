import { IsIn, IsString, MaxLength } from 'class-validator';
import { AssetQueryDto } from './assets.dto';
import type { AssetWarrantyFilter } from './asset-warranty';

/** Separate opt-in list query; no new fields are added to the legacy list. */
export class AssetWarrantyQueryDto extends AssetQueryDto {
  @IsIn(['expired', 'expiring_soon'])
  warranty!: AssetWarrantyFilter;
  @IsString()
  @MaxLength(10)
  asOf = '';
}

/** Complete counts accept only a calendar reference, never list filters or owner. */
export class AssetWarrantyOverviewQueryDto {
  @IsString()
  @MaxLength(10)
  asOf = '';
}
