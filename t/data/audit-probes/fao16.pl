package N; sub new { my ($c,$v,$nx)=@_; bless {v=>$v,nx=>$nx}, $c } package main; my $l; $l=N->new($_,$l) for 1..3; my $t=""; for (my $n=$l; $n; $n=$n->{nx}) { $t.=$n->{v} } print "$t\n";
