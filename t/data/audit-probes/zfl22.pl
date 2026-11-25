my @a=(1,2); my @b=("@a", shift(@a), "@a"); print join("|", @b), "\n";
