our @a = (1,2,3); { my $v = delete local $a[0]; print "$v;", defined $a[0] ? "d" : "u" } print "@a\n";
