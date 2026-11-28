my $ok = eval { 0 }; print defined $ok ? "d$ok" : "u", $@ eq "" ? "c" : "s", "\n";
