my %h=(a=>1); sub w { $h{b}=9 } my @k=keys %h; w(); print scalar(@k),"\n";
