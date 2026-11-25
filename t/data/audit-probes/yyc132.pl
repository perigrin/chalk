package C; my @a=(1,2,3); sub m { $a[0]=9; 0 } my @b=(@a, C->m); print "@b\n";
