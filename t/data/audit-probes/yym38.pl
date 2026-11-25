my @a=("a\n","b\n"); chomp for @a; my @b=qw(ab cd); tr/a-d/A-D/ for @b; my @c=(1,2); $_ *= $_ for @c; my @d=(" x "); s/^\s+|\s+$//g for @d; print "@a@b@c[@d]\n";
