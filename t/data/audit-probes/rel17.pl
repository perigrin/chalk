sub find { my ($t,@l)=@_; for my $i (0..$#l) { return $i if $l[$i]==$t } -1 } print find(3,1,2,3), find(9,1), "\n";
