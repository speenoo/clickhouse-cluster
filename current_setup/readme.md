# Readme

## Servers

- Node1: 40.160.21.209
    - This one is currently in use and we will phase in once the others are added

- Node 2: 40.160.32.78
    - This has a good amount of data loaded and is the holder of the xml setups in here
    - This will be our primary node in the future

- Node 3: 15.204.208.204
    - This is a smaller follower node for reads or data loading. 
    - Data loading has been a pain so I was thinking set it for this one only

All servers are on OVH dedicated bare metal. All are connected through coolify right now.

My goal is to setup node 2/3 in an easy deployment here.
Node 3 is fresh with pretty much nothing setup. 

## Summary

We are pulling in billions of traffic rows a day. We store it on a s3backend table and query it joined with some pretty large mergetree and embedded rocksdb tables. 

The traffic joins to our identity graph so we can identify the website traffic for our product. 

Right now we are running a single node on Node 1. Its doing good but we need more as we scale. 

I need an easy and replicable way to scale up these nodes. 

So we start with 2 and 3 then move to 1 once they work in prod. 

Node 2 has a good amount of data loaded idk how we can set it up without breaking shit. 