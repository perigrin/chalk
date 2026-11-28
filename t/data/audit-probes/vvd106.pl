my @a = (1,2,3); sub inc { $_++ for @_ } inc(@a[0,1] = (7,8)); print "@a\n";
