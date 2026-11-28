my ($ok, $err) = (eval { die "x\n"; 1 }, $@); print defined $ok ? "d" : "u", $err // "none";
