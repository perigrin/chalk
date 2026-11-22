my $h = {a=>1}; my $v = $h->{a}; $h->{a} = 2; my $w = $h->{a}; print "$v $w\n";
