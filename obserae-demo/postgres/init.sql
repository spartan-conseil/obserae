-- Demo dataset for the application backend.
CREATE TABLE IF NOT EXISTS customers (
    id     SERIAL PRIMARY KEY,
    name   TEXT NOT NULL,
    city   TEXT NOT NULL
);

INSERT INTO customers (name, city) VALUES
    ('Acme Corp',        'Paris'),
    ('Globex',           'Lyon'),
    ('Initech',          'Nantes'),
    ('Umbrella',         'Lille'),
    ('Hooli',            'Bordeaux'),
    ('Stark Industries', 'Toulouse'),
    ('Wayne Enterprises','Strasbourg'),
    ('Cyberdyne',        'Rennes')
ON CONFLICT DO NOTHING;
