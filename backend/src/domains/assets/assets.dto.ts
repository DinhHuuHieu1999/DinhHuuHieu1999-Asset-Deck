import { ASSET_LIST_SORTS, type AssetListSort } from './asset-sort';
import { Type } from 'class-transformer';
import {
  IsIn,
  IsInt,
  IsOptional,
  IsUUID,
  IsString,
  Matches,
  Max,
  MaxLength,
  Min,
  MinLength,
} from 'class-validator';

export const ASSET_STATUSES = [
  'in_use',
  'stored',
  'repair',
  'retired',
] as const;
export type AssetStatus = (typeof ASSET_STATUSES)[number];

/** Manual inventory input; identity, owner and timestamps cannot be submitted. */
export class AssetInputDto {
  @IsString()
  @MinLength(1)
  @MaxLength(120)
  @Matches(/^[^\0]*$/u)
  name!: string;
  @IsString()
  @MinLength(1)
  @MaxLength(64)
  @Matches(/^[^\0]*$/u)
  category!: string;
  @IsString()
  @MaxLength(120)
  @Matches(/^[^\0]*$/u)
  serial = '';
  @IsIn(ASSET_STATUSES)
  status!: AssetStatus;
  @IsString()
  @MaxLength(2000)
  @Matches(/^[^\0]*$/u)
  notes = '';
}

/** Replace a record only against the version actually loaded. */
export class AssetUpdateDto extends AssetInputDto {
  @IsInt()
  @Min(1)
  @Max(2147483646)
  version!: number;
}

/** Fixed page size and literal substring search, without owner-selected queries. */
export class AssetQueryDto {
  @IsIn(['all', 'unchecked', 'before', 'on_or_after'])
  checkMode?: 'all' | 'unchecked' | 'before' | 'on_or_after' = 'all';
  @IsString()
  @MaxLength(10)
  checkBefore?: string = '';
  @IsString()
  @MaxLength(10)
  checkOnOrAfter?: string = '';
  @IsIn(ASSET_LIST_SORTS)
  sort?: AssetListSort = 'updated_desc';
  @IsString()
  @MaxLength(120)
  @Matches(/^[^\0]*$/u)
  q = '';
  @IsIn(['', ...ASSET_STATUSES])
  status: AssetStatus | '' = '';
  @IsString()
  @MaxLength(64)
  @Matches(/^[^\0]*$/u)
  category?: string = '';
  @Type(() => Number)
  @IsInt()
  @Min(0)
  @Max(100000)
  offset = 0;
}

/** Advisory exact serial lookup; identity exclusion is not an ownership assertion. */
export class AssetSerialQueryDto {
  @IsString()
  @MaxLength(120)
  @Matches(/^[^\0]*$/u)
  serial = '';
  @IsOptional()
  @IsUUID()
  excludeId?: string;
}
