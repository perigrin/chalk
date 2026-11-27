my $h = {a=>{b=>1}}; { local $h->{a}{b} = 2; print $h->{a}{b} } print $h->{a}{b}, "\n";
