my $r = {a=>{b=>2}}; my $s = "$r->{a}{b}-$$r{a}->{b}"; print "$s\n";
