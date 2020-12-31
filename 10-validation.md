# End-to-End Validation

Now that you have a workload deployed, the [Fabrikam Drone Delivery Shipping app](./09-workload.md), you can start validating and exploring this reference implementation of the [AKS Fabrikam Drone Delivery](./). In addition to the workload, there are some observability validation you can perform as well.

## Validate the application is running

This section will help you to validate the workload is exposed correctly and responding to HTTP requests.
You can send delivery requests and check their statuses.

### Steps

1. Get Public IP of Application Gateway

   > :book: The app team conducts a final acceptance test to be sure that traffic is flowing end-to-end as expected, so they place a request against the Azure Application Gateway endpoint.

   ```bash
   # query the Azure Application Gateway Public Ip
   export APPGW_PUBLIC_IP=$(az deployment group show --resource-group rg-enterprise-networking-spokes -n spoke-shipping-dronedelivery --query properties.outputs.appGwPublicIpAddress.value -o tsv)
   ```

1. Send a request to <https://dronedelivery.fabrikam.com>.

   > :bulb: Since the certificate used for TLS is self-signed, the request disables TLS validation using the '-k' option.

   ```bash
   curl -X POST "https://dronedelivery.fabrikam.com/api/deliveryrequests" --resolve dronedelivery.fabrikam.com:443:$APPGW_PUBLIC_IP --header 'Content-Type: application/json' --header 'Accept: application/json' -k -d '{
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

1. Check the request status

   ```bash
   DELIVERY_ID=$(cat deliveryresponse.json | jq -r .deliveryId)
   curl "https://dronedelivery.fabrikam.com/api/deliveries/$DELIVERY_ID" --resolve dronedelivery.fabrikam.com:443:$APPGW_PUBLIC_IP --header 'Accept: application/json' -k
   ```

##  Further validate by following extra steps from the AKS Secure Baseline. _Optional_.

Navigate to [the AKS Secure Baseline to validate the Firewall, Azure Monitor Inisghts, and
more.](https://github.com/mspnp/aks-secure-baseline/blob/aeed3c9036d440979c4baa93f5b43a7c3e6d5375/10-validation.md#validate-web-application-firewall-functionality)

## Next step

:arrow_forward: [Clean Up Azure Resources](./11-cleanup.md)
