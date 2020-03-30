RG=TableDemo
LOC=centralus
STORAGE=mfstoragedemo01
TABLE_NAME=Demo

az group create -n $RG --location $LOC
az storage account create -n $STORAGE -g $RG --https-only

STORAGEKEY=$(az storage account keys list -g $RG -n $STORAGE --query "[?keyName=='key1'].value" --output tsv)

az storage table create -n $TABLE_NAME --account-name $STORAGE --account-key $STORAGEKEY

az storage entity insert --account-name $STORAGE --account-key $STORAGEKEY \
    --entity PartitionKey=AAA RowKey=BBB Content=ASDF2 \
    --if-exists fail --table-name $TABLE_NAME

az storage account update -n $STORAGE -g $RG --https-only --default-action Deny --bypass None