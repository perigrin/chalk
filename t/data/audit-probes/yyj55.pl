my @r = map { my $x = $_; map { "$x$_" } 1..2 } qw(a b); print "@r\n";
