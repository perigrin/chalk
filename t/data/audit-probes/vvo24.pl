my $r = {a=>1}; my @l = ((@$r{qw(a)} = (7)), $r->{a} = 9); print "@l\n";
