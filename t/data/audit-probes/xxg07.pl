my @a = (1,2,3); my ($f, @r) = @a; (@r, $f) = ($f, @r); print "$f|@r\n";
