my @a = (1,2,3); sub mod { $_[0] = 9 } mod(@a); mod($a[1]); mod(@a[2,0]); print "@a\n";
