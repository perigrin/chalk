our @s; our $d=0; sub rec { my $k=shift; $d++; push @s,$d; rec($k-1) if $k; $d-- } rec(2); print "@s $d\n";
