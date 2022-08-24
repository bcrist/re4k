    row 88: SuperWIDE steering
        1 : Route this cluster allocator's output to this MC
        0 : Route this cluster allocator's output to the cluster allocator for MC+4, wrapping around if above 15

    rows 74, 75: Cluster allocator steering
         0   0 : Route this cluster to the allocator for MC-2
         0   1 : Route this cluster to the allocator for MC+1
         1   0 : Route this cluster to this allocator
         1   1 : Route this cluster to the allocator for MC-1

