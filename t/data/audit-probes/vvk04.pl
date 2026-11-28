sub f { $_[0] = "n" } my @a = (1, 2); f($a[1]); my %h = (k => 1); f($h{k}); print "@a$h{k}\n";
