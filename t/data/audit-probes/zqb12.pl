our @a=(1,2); my $r=\@a; sub f { local @a=(5); "@$r" } print f(), "\n";
