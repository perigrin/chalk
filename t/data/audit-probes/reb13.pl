our $g=1; sub f { for my $i (1..3) { local $g=$i; return $g if $i==2 } 0 } my $v=f(); print "$v $g\n";
