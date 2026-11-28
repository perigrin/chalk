package O; sub m { wantarray ? "l" : "s" } package main; my @a = O->m; my $b = O->m; my ($c) = O->m; print "@a$b$c\n";
