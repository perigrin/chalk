use feature "try"; no warnings; sub f { my $l=""; try { die "x\n" } catch ($e) { $l.="c" } finally { $l.="f" } $l } print f(),"\n";
