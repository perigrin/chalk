my $o = "str"; my $r = eval { $o->method; 1 } ? "ok" : "died"; print "$r\n";
