my $c = eval { my $o = {}; $o->{a}{b}{c} = 1; scalar keys %$o }; print "$c\n";
