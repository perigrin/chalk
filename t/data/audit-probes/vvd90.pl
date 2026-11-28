my $r = {a=>1,b=>2}; my ($x, $y) = @$r{qw(a b)} = @$r{qw(b a)}; print "$x$y$r->{a}$r->{b}\n";
