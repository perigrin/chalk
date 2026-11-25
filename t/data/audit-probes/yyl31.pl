my @re = (qr/^a/, qr/b$/); my @w = qw(ab ba aa bb); print join(",", grep { my $w = $_; grep { $w =~ $_ } @re } @w), " ", join(",", grep { $_ =~ $re[0] && $_ =~ $re[1] } @w), "\n";
