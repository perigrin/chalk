my $h = {a=>1}; for my $i (1..2) { local $h->{a} = $h->{a} + $i; print $h->{a} } print $h->{a}, "\n";
