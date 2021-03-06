#!/bin/bash
set -e

# Load external input variables
source vars.sh

#
# Resource group
#
echo -e "### 🚀 Creating resource group..."
az group create -n $resGrp -l $location -o table

#
# Service principal
#
echo -e "\n### 🚀 Creating service principal..."
spPassword=$(az ad sp create-for-rbac --skip-assignment -n "$clusterName-sp" --query password -o tsv)

echo -e "\n### ⏰ Waiting 60 seconds for SP to fully propogate..."
sleep 60
spClientId=$(az ad sp list --spn "http://$clusterName-sp" --query "[0].appId" -o tsv)
echo -e "\n### 🔑 New service principal id: $spClientId"

#
# VNet and subnets
#
echo -e "\n### 🚀 Creating main AKS VNet and subnet..."
az network vnet create -g $resGrp --name $vnetName \
 --address-prefix "10.0.0.0/8" \
 --subnet-name $subnetName --subnet-prefix "10.240.0.0/16" -o table

echo -e "\n### 🔎 Assigning role to VNet..."
vnetId=$(az network vnet show -g $resGrp --name $vnetName --query id -o tsv)
az role assignment create --assignee $spClientId --scope $vnetId --role Contributor -o table

echo -e "\n### 🚀 Creating subnet for Virtual Nodes..."
az network vnet subnet create -g $resGrp --vnet-name $vnetName \
 --name $vnodesSubnetName \
 --address-prefixes "10.241.0.0/16" -o table

subnetId=$(az network vnet subnet show -n $subnetName -g $resGrp --vnet-name $vnetName --query "id" -o tsv)

#
# Monitoring
#
echo -e "\n### 🚀 Creating Log Analytics workspace..."
az resource create --resource-type Microsoft.OperationalInsights/workspaces \
 -n $logWorkspaceName \
 -g $resGrp \
 -l $location \
 -p '{}' -o table

workspaceId=$(az resource show -n $logWorkspaceName -g $resGrp --resource-type Microsoft.OperationalInsights/workspaces --query "id" -o tsv)

#
# Build the cluster! With features/options: 
# - Advanced network, autoscaler, VMSS, monitoring, RBAC, HTTP routing, network policy
#
echo -e "\n### 🚀 Creating AKS cluster, please wait..."
az aks create \
 --resource-group $resGrp \
 --name $clusterName \
 --location $location \
 --dns-name-prefix $clusterName \
 --kubernetes-version $kubeVersion \
 --node-vm-size $vmSize \
 --node-count $minNodes \
 --enable-cluster-autoscaler \
 --min-count $minNodes \
 --max-count $maxNodes \
 --enable-addons http_application_routing,monitoring \
 --network-plugin azure \
 --vnet-subnet-id $subnetId \
 --workspace-resource-id $workspaceId \
 --service-principal $spClientId \
 --client-secret $spPassword \
 --network-policy azure \
 --load-balancer-sku standard \
 --vm-set-type VirtualMachineScaleSets \
 --windows-admin-username $winAdminUser \
 --windows-admin-password $winAdminPwd \
 --verbose 

echo -e "\n### "
echo -e "### ✨ AKS cluster is now ready, running post deploy steps..."
echo -e "### "

#
# Post creation steps, comment out/in as required
#

# echo -e "\n### 👻 Enabling Virtual Nodes..."
# az aks enable-addons \
#   --resource-group $resGrp \
#   --name $clusterName \
#   --addons virtual-node \
#   --subnet-name $vnodesSubnetName
