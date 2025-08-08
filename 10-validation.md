# End-to-End Validation

Now that you have a workload deployed, the [Fabrikam Drone Delivery Shipping app](./09-workload.md), you can validate functionality and begin exploring this reference implementation of the [AKS Fabrikam Drone Delivery](./). In addition to the workload, there is some observability validation you can perform as well.

## Validate the application is running

This section will help you to validate the workload is exposed correctly and responding to HTTP requests.

### Steps

1. Get Public IP of Application Gateway.

    > :book: The app team conducts a final acceptance test to ensure that traffic is flowing end-to-end as expected. To do so, an HTTP request is submitted against the Azure Application Gateway endpoint.

   ```bash
   export APPGW_PUBLIC_IP=$(az deployment group show --resource-group rg-enterprise-networking-spokes-${LOCATION} -n spoke-shipping-dronedelivery --query properties.outputs.appGwPublicIpAddress.value -o tsv)
   ```

1. Send a request to https://dronedelivery.fabrikam.com.

   > :bulb: Since the certificate used for TLS is self-signed, the request disables TLS validation using the '-k' option.

   ```bash
   curl -v -X POST "https://dronedelivery.fabrikam.com/v0.1.0/api/deliveryrequests" --resolve dronedelivery.fabrikam.com:443:$APPGW_PUBLIC_IP --header 'Content-Type: application/json' --header 'Accept: application/json' -k -d '{
      "confirmationRequired": "None",
      "deadline": "",
      "dropOffLocation": "drop off",
      "expedited": true,
      "ownerId": "myowner",
      "packageInfo": {
        "packageId": "mypackage",
        "size": "Small",
        "tag": "mytag",
        "weight": 10
      },
      "pickupLocation": "my pickup",
      "pickupTime": "2019-05-08T20:00:00.000Z"
    }' > deliveryresponse.json
   ```

1. Check the request status.

   ```bash
   DELIVERY_ID=$(cat deliveryresponse.json | jq -r .deliveryId)
   curl -v "https://dronedelivery.fabrikam.com/v0.1.0/api/deliveries/$DELIVERY_ID" --resolve dronedelivery.fabrikam.com:443:$APPGW_PUBLIC_IP --header 'Accept: application/json' -k
   ```

## Validate the Distributed Tracing solution

   > :book: The app team decided to use [Application Insights](https://learn.microsoft.com/azure/azure-monitor/app/app-insights-overview) as their Application Performance Management (APM) tool. In a microservices architecture, making use of this tooling is critical when monitoring the application to detect anomalies and easily diagnose issues and quickly understand the dependencies between services.  The AKS Fabrikam Drone Delivery Shipping Application is a polyglot solution using .NET Core, Node.js, and Java.  Application Insights, which is part of Azure Monitor, can work with these languages and many others.  The app team also wanted to ensure that the telemetry being sent from the services was well contextualized in the Kubernetes world.  That's why they enriched the telemetry to incorporate image names, container information, and more.

### Steps

1. Execute the following command couple of times (2 or 3 executions should be enough).

   ```bash
   curl -X POST "https://dronedelivery.fabrikam.com/v0.1.0/api/deliveryrequests" --resolve dronedelivery.fabrikam.com:443:$APPGW_PUBLIC_IP --header 'Content-Type: application/json' --header 'Accept: application/json' -k -d '{
      "confirmationRequired": "None",
      "deadline": "",
      "dropOffLocation": "drop off",
      "expedited": true,
      "ownerId": "myowner",
      "packageInfo": {
        "packageId": "mypackage",
        "size": "Small",
        "tag": "mytag",
        "weight": 10
      },
      "pickupLocation": "my pickup",
      "pickupTime": "2020-12-08T20:00:00.000Z"
    }'
   ```

1. Wait for a couple of minutes for log entries to propagate, and then navigate to your Application Insights Azure service instance in the `rg-eshipping-dronedelivery` resource group. Then select `Application Map` under the `Investigate` section.

   A similar dependency map like the one below should be displayed.

![Application Insights depency map with messaging flow from Ingestion microservice to Workflow microservice and then from Workflow to Package, Drone Scheduler and Delivery microservices](./imgs/aks-fabrikam-dronedelivery-applicationmap.png)

## Validate the Horizontal Pod Autoscaling configuration

   > :book: The app team wants to ensure that the Fabrikam Drone Delivery applications are using cluster resources appropriately. Under load or seasonal spikes in traffic, the application should scale out by adding more pods. Once the load has lightened, the application should scale down the number of pods being used. To achieve this configuration, the app team has implemented Horizontal Pod Autoscaling (HPA) for all their microservices.

   > Note: the application is currently being deployed in `dev` mode in which autoscaling capabilites are disabled by default. Please deploy the apps by passing `--set autoscaling.enabled=true` to configure HPA resources in your AKS cluster.

1. Inspect CPU/Memory requests and limits.

   ```bash
   kubectl describe nodes --selector='agentpool=npuser01' | grep backend-dev
   ```

1. Get the HPA resources (optional).

    ```bash
   kubectl get hpa -n backend-dev
   ```

   > Note: if you've enabled the autoscaling capability when deploying the [workload](./09-workload.md), when a pod for a microservice exceeds the `CPU` limits, a new pod (or more) are going to be scheduled until the CPU desired target is met.

##  Further validate by following extra steps from the AKS Baseline *(optional)*

Navigate to [the AKS Baseline to validate the Firewall, Azure Monitor Insights, and
more.](https://github.com/mspnp/aks-baseline/blob/main/docs/deploy/11-validation.md#validate-web-application-firewall-functionality)

## Next step

:arrow_forward: [Clean Up Azure Resources](./11-cleanup.md)
