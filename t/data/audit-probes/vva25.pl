my $r = {a=>1}; { local $r->{a} = 8; print $r->{a} } print "$r->{a}\n";
