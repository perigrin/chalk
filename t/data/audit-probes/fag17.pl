my @a=(1,2); sub w { $a[0]=9 } my %h=(l=>[@a]); w(); print "@{$h{l}}\n";
