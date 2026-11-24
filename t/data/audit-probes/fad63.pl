our $g=1; sub f { local $g=2; return h() } sub h { die "h\n" } my $r = eval { f() } || $g; print "$r\n";
