#ABSTRACT: Simple Object Relational Mapping for Dancer

package Dancer::Plugin::ORMesque;
BEGIN {
  $Dancer::Plugin::ORMesque::VERSION = '0.0100';
}

use strict;
use warnings;
use base 'DBIx::Simple';

use Dancer qw/:syntax/;
use Dancer::Plugin;
use Dancer::Plugin::Database;

use SQL::Abstract;
use SQL::Interp;

my  $cfg =
    config->{plugins}->{Database};

# use Data::Dumper qw/Dumper/;


register dbi => sub {
    my    $dbh    = database;
    my    $self   = {};
    bless $self, 'Dancer::Plugin::ORMesque';
    
    warn "Error connecting to the database..." unless $dbh;
    warn "No database driver specified in the configuration file" unless $cfg->{driver};
    
    # MYSQL CONFIGURATION
    # load schema from connection for mysql
    if (lc($cfg->{driver}) eq 'mysql') {
        # load tables
        push @{$self->{schema}->{tables}}, $_->[0]
            foreach @{ $dbh->selectall_arrayref("SHOW TABLES") };
        # load table columns
        foreach my $table (@{$self->{schema}->{tables}}) {
            for ( @{ $dbh->selectall_arrayref("SHOW COLUMNS FROM `$table`") } ) {
                push @{$self->{schema}->{table}->{$table}->{columns}}, $_->[0];
                # find primary key
                $self->{schema}->{table}->{$table}->{primary_key} =
                    $_->[0] if lc($_->[3]) eq 'pri';
            }
        }
        # print Dumper $self;
        # exit;
    }
    
    # SQLite CONFIGURATION
    # load schema from connection for sqlite
    if (lc($cfg->{driver}) eq 'sqlite') {
        # load tables
        push @{$self->{schema}->{tables}}, $_->[2]
            foreach @{ $dbh->selectall_arrayref(
                        "SELECT * FROM sqlite_master WHERE type='table'") };
        # load table columns
        foreach my $table (@{$self->{schema}->{tables}}) {
            for ( @{ $dbh->selectall_arrayref("PRAGMA table_info('$table')") } ) {
                push @{$self->{schema}->{table}->{$table}->{columns}}, $_->[1];
                # find primary key
                $self->{schema}->{table}->{$table}->{primary_key} =
                    $_->[1] if lc($_->[5]) == 1;
            }
        }
        # print Dumper $self;
        # exit;
    }
    
    # setup reuseable connection using DBIx::Simple
    $self->{dbh} = DBIx::Simple->connect($dbh) or die DBIx::Simple->error;
    
    # define defaults
    $self->{target} = '';
    
    # create base accessors
    no warnings 'redefine';
    no strict 'refs';
    
    foreach my $table (@{$self->{schema}->{tables}}) {
        
            my $class           = ref($self);
            my $method          = $class    .  "::" . lc $table;
            my $package_name    = $class    .  "::" . ucfirst $table;
            my $package         = "package $package_name;" . q|
            
            use base 'Dancer::Plugin::ORMesque';
            
            sub new {
                my ($class, $base, $table) = @_;
                my $self            = {};
                bless $self, $class;
                $self->{table}      = $table;
                $self->{where}      = {};
                $self->{order}      = [];
                $self->{key}        = $base->{schema}->{table}->{$table}->{primary_key};
                $self->{collection} = [];
                $self->{cursor}     = 0;
                $self->{current}    = {};
                $self->{schema}     = $base->{schema};
                $self->{dbh}        = $base->{dbh};
                
                # build database objects
                $self->{configuration} = $cfg;
                
                foreach my $column (@{$self->{schema}->{table}->{$table}->{columns}}) {
                    $self->{current}->{$column} = '';
                    my $attribute = $class . "::" . $column;
                    *{$attribute} = sub {
                        my ($self, $data) = @_;
                        if (defined $data) {
                            $self->{current}->{$column} = $data;
                            return $data;
                        }
                        else {
                            return
                                $self->{current}->{$column};
                        }
                    };
                }
                
                return $self;
            }
            1;
            |;
            eval $package;
            die print $@ if $@; # debugging
            *{$method}  = sub {
                return $package_name->new($self, $table);
            };
            # build dbo table
            
    }
    return $self;
};


sub next {
    my $dbo     = shift;
    
    my $next    = $dbo->{cursor} <= (int(@{$dbo->{collection}})-1) ? 1 : 0;
    $dbo->{current}
                = $dbo->{collection}->[$dbo->{cursor}] || {};
                  $dbo->{cursor}++;
    
    return  $next;
}


sub first {
    my $dbo     = shift;
    
    $dbo->{cursor}  = 0;
    $dbo->{current} = $dbo->{collection}->[0] || {};
    
    return $dbo->current;
}


sub last {
    my $dbo     = shift;
    
    $dbo->{cursor}  = (int(@{$dbo->{collection}})-1);
    $dbo->{current} = $dbo->{collection}->[$dbo->{cursor}] || {};
    
    return $dbo->current;
}


sub collection {
    return shift->{collection};
}


sub current {
    return shift->{current};
}


sub clear {
    my $dbo     = shift;
    
    foreach my $column (keys %{$dbo->{current}}) {
        $dbo->{current}->{$column} = '';
    }
    
    $dbo->{collection} = [];
    
    return $dbo;
}


sub key {
    shift->{key};
}


sub return {
    my $dbo     = shift;
    my %where   = %{ $dbo->current };
    
    delete $where{$dbo->key} if $dbo->key;
    
    $dbo->read(\%where)->last;
    
    return $dbo->current;
}


sub count {
    my $dbo = shift;
    return scalar @{$dbo->{collection}};
};


sub create {
    my $dbo     = shift;
    my $input   = shift || {};
    my @columns = keys %{$dbo->{current}};
    
    die "Cannot create an entry in table ($dbo->{table}) without any input parameters."
        unless keys %{$input};
    
    # process direct input
    if ($input) {
        foreach my $i (keys %{$input}) {
            if (defined $dbo->{current}->{$i}) {
                $dbo->{current}->{$i} = $input->{$i};
            }
        }
    }
    
    # insert
    $dbo->{dbh}->insert($dbo->{table}, $dbo->{current});
    
    return $dbo;
};


sub read {
    my $dbo     = shift;
    my $where   = shift || {};
    my $order   = shift || [];
    my $table   = $dbo->{table};
    my @columns = keys %{ $dbo->{current} };
    
    # generate a where primary_key = ? clause
    if ($where && ref($where) ne "HASH") {
        $where = {
            $dbo->key => $where
        };
    }
    
    $dbo->{collection}  =
        $dbo->{dbh}->select($table, \@columns, $where, $order)->hashes;
    $dbo->{cursor}      = 0;
    $dbo->{current}     = $dbo->{collection}->[0] || {};
    
    return $dbo;
};


sub update {
    my $dbo     = shift;
    my $input   = shift || {};
    my $where   = shift || {};
    my $table   = $dbo->{table};
    my @columns = keys %{ $dbo->{current} };
    
    # process direct input
    die "Attempting to update an entry in table ($dbo->$table) without any input."
        unless keys %{$input};
    
    # generate a where primary_key = ? clause
    if ($where && ref($where) ne "HASH") {
        $where = {
            $dbo->key => $where
        };
    }
    
    $dbo->{dbh}->update($table, $input, $where) if keys %{$input};
    
    return $dbo;
};


sub delete {
    my $dbo     = shift;
    my $where   = shift || {};
    my $table   = $dbo->{table};
    
    # process where clause
    if ($where && $dbo->key && ref($where) ne "HASH") {
        $where = {
            $dbo->key => $where
        };
    }
    else {
        die "Cannot delete without a proper where clause, " .
            "use delete_all to purge the entire database table";
    }
    
    $dbo->{dbh}->delete($table, $where);
    
    return $dbo;
};


sub delete_all {
    my $dbo     = shift;
    my $table   = $dbo->{table};
    
    $dbo->{dbh}->delete($table);
    
    return $dbo;
};

# utilize DBIx::Simple query, and SQL::Interp iquery methods

sub query {
    return shift->{dbh}->query(@_);
}

sub iquery {
    return shift->{dbh}->iquery(@_);
}

register_plugin;

1;

__END__
=pod

=head1 NAME

Dancer::Plugin::ORMesque - Simple Object Relational Mapping for Dancer

=head1 VERSION

version 0.0100

=head1 SYNOPSIS

Dancer::Plugin::ORMesque is NOT a full-featured object relational
mapper but is an ORM none the less whereby it creates and provides a database
connection to the database of your choice and automatically creates objects
and accessors for use in your application code without the need of having to
write SQL. Dancer::Plugin::ORMesque uses L<SQL::Abstract> querying syntax. This
module uses DBIx::Simple as a base class but only the query and iquery methods
are made available.

Connection details will be taken from your Dancer application config file,
and should be specified as, for example:

    plugins:
      Database:
        driver: 'mysql'
        database: 'test'
        host: 'localhost'
        username: 'myusername'
        password: 'mypassword'
        connectivity-check-threshold: 10
        dbi_params:
            RaiseError: 1
            AutoCommit: 1
        on_connect_do: ["SET NAMES 'utf8'", "SET CHARACTER SET 'utf8'" ]

The connection functionality is imported from L<Dancer::Plugin::Database>, please
look into that plugin for more information. Please note that even if you use supply
a DSN directly in your configuration file you need to also specify a driver directive.

    # Use the dbi (database interface) keyword to establish a new connection to
    # the database then access users (the users table) and store the reference in
    # local variable $users
    
    my $user = dbi->users;
    
    # Grab the first record, not neccessary if operating on only one record
    
    $user->read;
    
    # SQL::Abstract where clause passed to the "read" method
    
    $user->read({
        'column' => 'query'
    });
    
    $user->first;
    $user->last;
    
    # How many records in collection
    
    $user->count
    
    for (0..$user->count) {
        print $user->column;
        $user->column('new stuff');
        $user->update($user->current, $user->id);
        $user->next;
    }
    
    # The database objects main accessors are CRUD (create, read, update, and delete)
    
    $user->create;
      $user->read;
        $user->update;
          $user->delete;
    
    # Also, need direct access to the resultset?
    
    $user->collection; # returns an array of hashrefs
    $user->current;    # return a hashref of the current row in the collection

=head1 METHODS

=head2 dbi

    The dbi method/keyword instantiates a new Dancer::Plugin::ORMesque instance
    which uses the datasource configuration details in your configuration file
    to create database objects and accessors.
    
    my $db = dbi;

=head1 EXPERIMENTAL

This plugin is highly **experimental** and subject to radical design changes based on
random flights-of-fancy. Currently the only databased supported are MySQL and SQLite
but more support will be added once I have a stable model to with with. Please
give feedback.

=head2 next

    The next method instructs the database object to continue to the next
    row if it exists.
    
    dbi->table->next;
    
    while (dbi->table->next) {
        ...
    }

=head2 first

    The first method instructs the database object to continue to return the first
    row in the resultset.
    
    dbi->table->first;

=head2 last

    The last method instructs the database object to continue to return the last
    row in the resultset.
    
    dbi->table->last;

=head2 collection

    The collection method return the raw resultset object.
    
    dbi->table->collection;

=head2 current

    The current method return the raw row resultset object of the position in
    the resultset collection.
    
    dbi->table->current;

=head2 clear

    The clear method empties all resultset containers. This method should be used
    when your ready to perform another operation (start over) without initializing
    a new object.
    
    dbi->table->clear;

=head2 key

    The key method finds the database objects primary key if its defined.
    
    dbi->table->key;

=head2 return

    The return method queries the database for the last created object(s).
    
    my $new_record = dbi->table->create(...)->return;

=head2 count

    The count method returns the number of items in the resultset of the
    object it's called on.
    
    my $count = dbi->table->read->count;

=head2 create

    Caveat 1: The create method will remove the primary key if the column
    is marked as auto-incremented ...
    
    The create method creates a new entry in the datastore.
    takes 1 arg: hashref (SQL::Abstract fields parameter)
    
    dbi->table->create({
        'column_a' => 'value_a',
    });
    
    # create a copy of an existing record
    my $user = dbi->users;
    $user->read->first;
    $user->full_name('Copy of ' . $user->full_name);
    $user->user_name('foobarbaz');
    $user->create($user->current);

    # get newly created record
    $user->return;
    
    print $user->id; # new record id
    print $user->full_name;

=head2 read

    The read method fetches records from the datastore.
    Takes 2 arg.
    
    arg 1: hashref (SQL::Abstract where parameter) or scalar
    arg 2: arrayref (SQL::Abstract order parameter) - optional
    
    dbi->table->read({
        'column_a' => 'value_a',
    });
    
    or
    
    dbi->table->read(1);
    
    # return arrayref from read (select) method
    my $records = dbi->table->read->collection

=head2 update

    The update method alters an existing record in the datastore.
    Takes 2 arg.
    
    arg 1: hashref (SQL::Abstract fields parameter)
    arg 2: arrayref (SQL::Abstract where parameter) or scalar - optional
    
    dbi->table->update({
        'column_a' => 'value_a',
    },{
        'where_column_a' => '...'
    });
    
    or
    
    dbi->table->update({
        'column_a' => 'value_a',
    }, 1);

=head2 delete

    The delete method is prohibited from deleting an entire database table and
    thus requires a where clause. If you intentionally desire to empty the entire
    database then you may use the delete_all method.
    
    dbi->table->delete({
        'column_a' => 'value_a',
    });
    
    or
    
    dbi->table->delete(1);

=head2 delete

    The delete_all method is use to intentiionally empty the entire database table.
    
    dbi->table->delete_all;

=head1 AUTHOR

  Al Newkirk <awncorp@cpan.org>

=head1 COPYRIGHT AND LICENSE

This software is copyright (c) 2010 by awncorp.

This is free software; you can redistribute it and/or modify it under
the same terms as the Perl 5 programming language system itself.

=cut

