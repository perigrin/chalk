my @m=([1,2],[3,4]); $_->[0]*=10 for @m; my @c=map { $_->[0] } @m; print "@c\n";
