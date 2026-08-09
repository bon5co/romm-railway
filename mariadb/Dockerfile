# MariaDB for RomM on Railway.
#
# The database name and user are baked rather than published as template
# variables: templateGenerate drops a variable whose default is a literal and
# republishes it as a blank REQUIRED field on the deploy form. Only the
# passwords stay variables, and those are ${{secret(32)}} expressions, which
# survive generation.
FROM mariadb:11.4

ENV MARIADB_DATABASE=romm \
    MARIADB_USER=romm
