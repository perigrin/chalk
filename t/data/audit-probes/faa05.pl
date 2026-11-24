sub f { for (@_) { $_*=2 } } my ($a,$b)=(1,2); f($a,$b); print "$a$b\n";
