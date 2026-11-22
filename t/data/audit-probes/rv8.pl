use v5.42; use experimental "class"; class K { field @f = (1); method m { my @a = @f; push @f, 2; my @b = @f; return "@a|@b" } } print K->new->m, "\n";
