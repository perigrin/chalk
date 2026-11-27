sub f { $_[0] ||= 3; $_[1] //= 4; $_[2] &&= 5 } my ($p,$q,$r)=(0,undef,1); f($p,$q,$r); print "$p$q$r\n";
