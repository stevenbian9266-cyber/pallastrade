-- PallasTrade seed data
BEGIN;

INSERT INTO pallastrade_shipping_categories (name, created_at, updated_at) 
SELECT 'Default', NOW(), NOW() WHERE NOT EXISTS (SELECT 1 FROM pallastrade_shipping_categories WHERE name='Default');

INSERT INTO pallastrade_stock_locations (name, "default", active, created_at, updated_at) 
SELECT 'Default', true, true, NOW(), NOW() WHERE NOT EXISTS (SELECT 1 FROM pallastrade_stock_locations WHERE name='Default');

INSERT INTO pallastrade_taxonomies (name, store_id, created_at, updated_at) 
SELECT 'Categories', id, NOW(), NOW() FROM pallastrade_stores LIMIT 1;

INSERT INTO pallastrade_taxons (taxonomy_id, name, permalink, position, created_at, updated_at) 
SELECT id, 'Categories', 'categories', 0, NOW(), NOW() FROM pallastrade_taxonomies WHERE name='Categories';

UPDATE pallastrade_taxons SET parent_id = sub.id 
FROM (SELECT id FROM pallastrade_taxons WHERE name='Categories' AND parent_id IS NULL) sub 
WHERE name='Categories' AND parent_id IS NULL;

INSERT INTO pallastrade_taxons (taxonomy_id, parent_id, name, permalink, position, created_at, updated_at) 
SELECT t.id, (SELECT id FROM pallastrade_taxons WHERE name='Categories' AND parent_id IS NOT NULL), 'Clothing', 'categories/clothing', 1, NOW(), NOW() 
FROM pallastrade_taxonomies t WHERE t.name='Categories';

INSERT INTO pallastrade_taxons (taxonomy_id, parent_id, name, permalink, position, created_at, updated_at) 
SELECT t.id, (SELECT id FROM pallastrade_taxons WHERE name='Categories' AND parent_id IS NOT NULL), 'Accessories', 'categories/accessories', 2, NOW(), NOW() 
FROM pallastrade_taxonomies t WHERE t.name='Categories';

CREATE OR REPLACE FUNCTION mkprod(p_name text, p_slug text, p_desc text, p_price numeric) RETURNS void AS $$
DECLARE
    vs integer; vsh integer; vst integer; vp integer; vv integer;
BEGIN
    SELECT id INTO vs FROM pallastrade_stores LIMIT 1;
    SELECT id INTO vsh FROM pallastrade_shipping_categories LIMIT 1;
    SELECT id INTO vst FROM pallastrade_stock_locations LIMIT 1;
    INSERT INTO pallastrade_products (name, slug, description, available_on, status, shipping_category_id, store_id, created_at, updated_at)
    VALUES (p_name, p_slug, p_desc, NOW(), 'active', vsh, vs, NOW(), NOW()) ON CONFLICT (slug) DO NOTHING;
    SELECT id INTO vp FROM pallastrade_products WHERE slug=p_slug;
    INSERT INTO pallastrade_products_stores (product_id, store_id, created_at, updated_at) VALUES (vp, vs, NOW(), NOW()) ON CONFLICT DO NOTHING;
    INSERT INTO pallastrade_variants (product_id, is_master, track_inventory, created_at, updated_at) VALUES (vp, true, true, NOW(), NOW());
    SELECT id INTO vv FROM pallastrade_variants WHERE product_id=vp AND is_master=true;
    INSERT INTO pallastrade_prices (variant_id, amount, currency, created_at, updated_at) VALUES (vv, p_price, 'USD', NOW(), NOW());
    INSERT INTO pallastrade_stock_items (stock_location_id, variant_id, count_on_hand, backorderable, created_at, updated_at) VALUES (vst, vv, 100, true, NOW(), NOW());
END;
$$ LANGUAGE plpgsql;

SELECT mkprod('PallasTrade Classic T-Shirt', 'pallastrade-classic-t-shirt', 'Premium cotton t-shirt.', 29.99);
SELECT mkprod('PallasTrade Hoodie', 'pallastrade-hoodie', 'Premium fleece hoodie.', 59.99);
SELECT mkprod('PallasTrade Cap', 'pallastrade-cap', 'Classic baseball cap.', 24.99);
SELECT mkprod('PallasTrade Coffee Mug', 'pallastrade-coffee-mug', 'Ceramic mug.', 14.99);
SELECT mkprod('PallasTrade Tote Bag', 'pallastrade-tote-bag', 'Canvas tote bag.', 19.99);

DROP FUNCTION mkprod;
COMMIT;
