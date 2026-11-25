my $t={v=>1,k=>[{v=>2,k=>[]},{v=>3,k=>[{v=>4,k=>[]}]}]}; sub sum { my $n=shift; my $s=$n->{v}; $s+=sum($_) for @{$n->{k}}; $s } print sum($t), "\n";
