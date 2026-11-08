/// Supported server-side inventory ordering; never sort an isolated page locally.
const assetSorts = ['updated_desc', 'name_asc'];

/// List-only extension; serialized selection schemas retain assetSorts.
const assetListSorts = [...assetSorts, 'checked_asc'];
