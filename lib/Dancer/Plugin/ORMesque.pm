#ABSTRACT: Light ORM for Dancer

package Dancer::Plugin::ORMesque;

use strict;
use warnings;

use Dancer qw/:syntax/;
use Dancer::Plugin;
use ORMesque;

our $VERSION = '1.112180'; # VERSION


my $schemas = {};

register db => sub {
    my $name = shift;
    my $cfg = plugin_setting;

    if (not defined $name) {
        ($name) = keys %$cfg or die "No schemas are configured";
    }

    return $schemas->{$name} if $schemas->{$name};

    my $options = $cfg->{$name} or die "The schema $name is not configured";
    
    my @conn_info = $options->{connect_info}
        ? @{$options->{connect_info}}
        : @$options{qw(dsn user pass options)};

    # pckg should be deprecated
    my $schema_class = $options->{schema_class} || $options->{pckg};

    if ($schema_class) {
        $schema_class =~ s/-/::/g;
        eval "use $schema_class";
        if ( my $err = $@ ) {
            die "error while loading $schema_class : $err";
        }
        $schemas->{$name} = $schema_class->new(@conn_info)
    } else {
        $schemas->{$name} = ORMesque->new(@conn_info);
    }

    return $schemas->{$name};
};

register_plugin;

1;

__END__
=pod

=head1 NAME

Dancer::Plugin::ORMesque - Light ORM for Dancer

=head1 VERSION

version 1.112180

=head1 SYNOPSIS

Dancer::Plugin::ORMesque is a lightweight ORM for Dancer supporting SQLite, MySQL, 
PostgreSQL and more making it a great alternative to L<Dancer::Plugin::Database>
if you are looking for a bit more automation and a fair alternative to
Dancer::Plugin::DBIC when you don't have the time, need or desire to learn
L<Dancer::Plugin::DBIC> and L<DBIx::Class>. Dancer::Plugin::ORMesque is an
object relational mapper for Dancer based on the L<ORMesque> module using
L<SQL::Abstract> querying syntax.

Connection details will be taken from your Dancer application config file,
and should be specified as, for example:

    plugins:
      ORMesque:
        connection_name:
          dsn:  "dbi:SQLite:dbname=./foo.db"

    # Use the db() keyword to establish a new connection to the database then
    # access your tables as follows:
    
    my $user = db->users;
    
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
    
    # The db() method/keyword instantiates a new Dancer::Plugin::ORMesque instance
    # which uses the datasource configuration details in your configuration file
    # to create database objects and accessors.
    
    my $db = db();

=head1 CONFIGURATION

Connection details will be grabbed from your L<Dancer> config file.
For example: 

    plugins:
      ORMesque:
        foo:
          dsn: dbi:SQLite:dbname=./foo.db
        bar:
          schema_class: MyApp::Model
          dsn:  dbi:mysql:db_foo
          user: root
          pass: secret
          options:
            RaiseError: 1
            PrintError: 1

Each schema configuration *must* have a dsn option.
The dsn option should be the L<DBI> driver connection string.
All other options are optional.

If a schema_class option is not provided, then L<ORMesque> will auto load the
schema based on the database tables and columns.

The schema_class option, if provided, should be a proper Perl package name that
Dancer::Plugin::ORMesque will use as a class.

Optionally, a database configuation may have user, pass and options paramters
as described in the documentation for connect() in L<DBI>.

    # Note! You can also declare your connection information with the
    # following syntax:
    plugings:
      ORMesque:
        foo:
          connect_info:
            - dbi:mysql:db_foo
            - root
            - secret
            -
              RaiseError: 1
              PrintError: 1

=head1 AUTHOR

Al Newkirk <awncorp@cpan.org>

=head1 COPYRIGHT AND LICENSE

This software is copyright (c) 2010 by awncorp.

This is free software; you can redistribute it and/or modify it under
the same terms as the Perl 5 programming language system itself.

=cut

