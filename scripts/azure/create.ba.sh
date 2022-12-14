#!/bin/bash

# Change these values!
YourID="jc221101"
Location="westcentralus"

RGName="rg-az220"

IoTHubName="iot-az220-training-$YourID"
DeviceID="sensor-th-0055"
StorageAccountName="staz220training$YourID"
TsiName="tsi-az220-training-$YourID"

# ensure variables have been set
if [ $YourID = "{your-id}" ] || [ $Location = "{your-location}" ]
then
    echo "You must change the YourID and/or Location values"
    exit 1
fi

# Setup colored output
YELLOW='\033[0;33m'
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# functions
reportStatus() {
    if [ -z "$1" ]
    then
        return
    fi
    if [ $1 -eq "0" ]
    then
        printf "${GREEN}Succeeded${NC}\n"
    else
        printf "${RED}Failed - ${2}${NC}\n"
        echo $2 >> build.log
    fi
}

# build log file
rm build.log.old 2> /dev/null
cp build.log build.log.old 2> /dev/null
echo "Building Lab Resources" > build.log

# create resource group
printf "${YELLOW}Create resource group ${RGName} - ${NC}"
exists=$( az group exists --name rg-az220 -o tsv )
if [ "${exists}" == "true" ]
then
    printf "${GREEN}Already exists\n${NC}"
else
    output=$( az group create --name $RGName --location $Location -o json >> build.log 2>&1 )
    reportStatus $? "$output"
fi

# create IoT Hub
printf "${YELLOW}Create IoT Hub $IoTHubName - ${NC}"
exists=$( az iot hub list --query "[?contains(name, '${IoTHubName}')].name" -o tsv )
if [ "${exists}" == "${IoTHubName}" ]
then
    printf "${GREEN}Already exists\n${NC}"
else
    output=$( az iot hub create --name $IoTHubName -g $RGName --sku S1 --location $Location -o json >> build.log 2>&1 )
    reportStatus $? "$output"
fi

# create a device ID using Symmetric Key Auth and Connect it to the IoT Hub
printf "${YELLOW}Create device ${DeviceID} - ${NC}"
exists=$( az iot hub device-identity list  --hub-name $IoTHubName --query "[?contains(deviceId, '${DeviceID}')].deviceId" -o tsv )
if [ "${exists}" == "${DeviceID}" ]
then
    printf "${GREEN}Already exists\n${NC}"
else
    output=$( az iot hub device-identity create --hub-name $IoTHubName --device-id $DeviceID -o json >> build.log 2>&1  )
    reportStatus $? "$output"
fi

# Create a Storage Account
printf "${YELLOW}Create storage account ${StorageAccountName} - ${NC}"
exists=$( az storage account list --resource-group ${RGName} --query "[?contains(name, '${StorageAccountName}')].name" -o tsv )
if [ "${exists}" == "${StorageAccountName}" ]
then
    printf "${GREEN}Already exists\n${NC}"
else
    output=$( az storage account create --name $StorageAccountName --resource-group $RGName --location $Location --sku Standard_LRS -o table >> build.log 2>&1  )
    reportStatus $? "$output"
fi

# Create Time Series Insights
printf "${YELLOW}Create Time Series Insights ${TsiName} - ${NC}"
exists=$( az tsi environment list --resource-group ${RGName} --query "[?contains(name, '${TsiName}')].name" -o tsv )
if [ "${exists}" == "${TsiName}" ]
then
    printf "${GREEN}Already exists\n${NC}"
else
    StorageKey=$( az storage account keys list -g $RGName -n $StorageAccountName --query [0].value --output tsv )
    output=$( az tsi environment gen2 create -g $RGName -n $TsiName --location $Location --sku  name="L1" capacity=1 --id-properties name='$dtId' type=String --storage-configuration account-name=$StorageAccountName management-key=$StorageKey -o table >> build.log 2>&1  )
    reportStatus $? "$output"
fi

# Create Time Series Insights Access Policy
printf "${YELLOW}Create Time Series Insights Access Policy access1 - ${NC}"
exists=$( az tsi access-policy list -g ${RGName} --environment-name $TsiName --query "[?contains(name, 'access1')].name" -o tsv )
if [ "${exists}" == "access1" ]
then
    printf "${GREEN}Already exists\n${NC}"
else
    ObjectId=$( az ad signed-in-user show --query objectId -o tsv )
    output=$( az tsi access-policy create -g $RGName --environment-name $TsiName --name "access1" --principal-object-id $ObjectId  --description "ADT Access Policy" --roles Contributor Reader  -o table >> build.log 2>&1  )
    reportStatus $? "$output"
fi

# Register resource providers
printf "${YELLOW}Ensuring resource providers are registered - ${NC}"
az provider register --namespace "Microsoft.EventGrid" --accept-terms >> build.log 2>&1
az provider register --namespace "Microsoft.EventHub" --accept-terms >> build.log 2>&1
az provider register --namespace "Microsoft.TimeSeriesInsights" --accept-terms >> build.log 2>&1
printf "${GREEN}Succeeded\n${NC}"

echo "Configuration Data:"
echo "------------------------------------------------"

# display the iothubowner connection string for the IoT Hub
echo "$IoTHubName Service connectionstring:"
az iot hub connection-string show --query connectionString --hub-name $IoTHubName -o tsv
echo ""

echo "$DeviceID device connection string:"
az iot hub device-identity connection-string show --hub-name $IoTHubName --device-id $DeviceID -o tsv
echo ""

echo "$IoTHubName eventhub endpoint:"
az iot hub show --query properties.eventHubEndpoints.events.endpoint --name $IoTHubName -o tsv
echo ""

echo "$IoTHubName eventhub path:"
az iot hub show --query properties.eventHubEndpoints.events.path --name $IoTHubName -o tsv
echo ""

echo "$IoTHubName eventhub SaS primarykey:"
az iot hub policy show --name service --query primaryKey --hub-name $IoTHubName -o tsv
echo ""

echo "Azure Storage Account for function: ${StorageAccountName}"
echo ""
