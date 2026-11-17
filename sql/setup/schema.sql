--
-- PostgreSQL database dump
--

\restrict 5jnHZeUAlBtAj1qiNZOYA1QcAVkyOWev6ThGCS9btQjPFlPUeHx2TunI1waSa4B

-- Dumped from database version 18.6
-- Dumped by pg_dump version 18.6

-- Started on 2026-11-17 11:03:51 MSK

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET transaction_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- TOC entry 4 (class 2615 OID 2200)
-- Name: public; Type: SCHEMA; Schema: -; Owner: pg_database_owner
--

CREATE SCHEMA public;


ALTER SCHEMA public OWNER TO pg_database_owner;

--
-- TOC entry 3904 (class 0 OID 0)
-- Dependencies: 4
-- Name: SCHEMA public; Type: COMMENT; Schema: -; Owner: pg_database_owner
--

COMMENT ON SCHEMA public IS 'standard public schema';


SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- TOC entry 219 (class 1259 OID 16820)
-- Name: customers; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.customers (
    customer_id character varying(32) NOT NULL,
    customer_unique_id character varying(32) NOT NULL,
    customer_zip_code_prefix character(5) NOT NULL,
    customer_city character varying(50) NOT NULL,
    customer_state character(2) NOT NULL,
    CONSTRAINT chk_customer_state CHECK ((customer_state ~ '^[A-Z]{2}$'::text)),
    CONSTRAINT chk_customer_zip CHECK ((customer_zip_code_prefix ~ '^[0-9]{5}$'::text))
);


ALTER TABLE public.customers OWNER TO postgres;

--
-- TOC entry 220 (class 1259 OID 16829)
-- Name: geolocation; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.geolocation (
    geolocation_zip_code_prefix character(5) NOT NULL,
    geolocation_lat double precision NOT NULL,
    geolocation_lng double precision NOT NULL,
    geolocation_city character varying(50),
    geolocation_state character(2),
    CONSTRAINT chk_geo_lat CHECK (((geolocation_lat >= ('-90'::integer)::double precision) AND (geolocation_lat <= (90)::double precision))),
    CONSTRAINT chk_geo_lng CHECK (((geolocation_lng >= ('-180'::integer)::double precision) AND (geolocation_lng <= (180)::double precision)))
);


ALTER TABLE public.geolocation OWNER TO postgres;

--
-- TOC entry 221 (class 1259 OID 16833)
-- Name: order_items; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.order_items (
    order_id character varying(32) NOT NULL,
    order_item_id integer NOT NULL,
    product_id character varying(32) NOT NULL,
    seller_id character varying(32) NOT NULL,
    shipping_limit_date timestamp without time zone NOT NULL,
    price numeric(10,2) NOT NULL,
    freight_value numeric(10,2) NOT NULL,
    CONSTRAINT chk_freight_nonneg CHECK ((freight_value >= (0)::numeric)),
    CONSTRAINT chk_order_item_id_positive CHECK ((order_item_id >= 1)),
    CONSTRAINT chk_price_nonneg CHECK ((price >= (0)::numeric))
);


ALTER TABLE public.order_items OWNER TO postgres;

--
-- TOC entry 223 (class 1259 OID 16845)
-- Name: order_reviews; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.order_reviews (
    review_id character varying(32) NOT NULL,
    order_id character varying(32) NOT NULL,
    review_score integer NOT NULL,
    review_comment_title text,
    review_comment_message text,
    review_creation_date timestamp without time zone NOT NULL,
    review_answer_timestamp timestamp without time zone NOT NULL,
    CONSTRAINT chk_answer_after_creation CHECK ((review_answer_timestamp >= review_creation_date)),
    CONSTRAINT chk_review_score CHECK (((review_score >= 1) AND (review_score <= 5)))
);


ALTER TABLE public.order_reviews OWNER TO postgres;

--
-- TOC entry 224 (class 1259 OID 16854)
-- Name: orders; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.orders (
    order_id character varying(32) NOT NULL,
    customer_id character varying(32) NOT NULL,
    order_status character varying(12) NOT NULL,
    order_purchase_timestamp timestamp without time zone NOT NULL,
    order_approved_at timestamp without time zone,
    order_delivered_carrier_date timestamp without time zone,
    order_delivered_customer_date timestamp without time zone,
    order_estimated_delivery_date timestamp without time zone NOT NULL,
    CONSTRAINT chk_approved_after_purchase CHECK ((order_approved_at >= order_purchase_timestamp)),
    CONSTRAINT chk_delivered_after_purchase CHECK ((order_delivered_customer_date >= order_purchase_timestamp)),
    CONSTRAINT chk_estimated_after_purchase CHECK ((order_estimated_delivery_date >= order_purchase_timestamp)),
    CONSTRAINT chk_order_status CHECK (((order_status)::text = ANY ((ARRAY['created'::character varying, 'approved'::character varying, 'invoiced'::character varying, 'processing'::character varying, 'shipped'::character varying, 'delivered'::character varying, 'canceled'::character varying, 'unavailable'::character varying])::text[])))
);


ALTER TABLE public.orders OWNER TO postgres;

--
-- TOC entry 222 (class 1259 OID 16841)
-- Name: payments; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.payments (
    order_id character varying(32) NOT NULL,
    payment_sequential integer NOT NULL,
    payment_type character varying(32) NOT NULL,
    payment_installments integer NOT NULL,
    payment_value numeric(10,2) NOT NULL,
    CONSTRAINT chk_installments_nonneg CHECK ((payment_installments >= 0)),
    CONSTRAINT chk_payment_seq_positive CHECK ((payment_sequential >= 1)),
    CONSTRAINT chk_payment_type CHECK (((payment_type)::text = ANY ((ARRAY['credit_card'::character varying, 'boleto'::character varying, 'voucher'::character varying, 'debit_card'::character varying, 'not_defined'::character varying])::text[]))),
    CONSTRAINT chk_payment_value_nonneg CHECK ((payment_value >= (0)::numeric))
);


ALTER TABLE public.payments OWNER TO postgres;

--
-- TOC entry 227 (class 1259 OID 16872)
-- Name: product_category_name_translation; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.product_category_name_translation (
    product_category_name text CONSTRAINT product_category_name_translatio_product_category_name_not_null NOT NULL,
    product_category_name_english text CONSTRAINT product_category_name_trans_product_category_name_engl_not_null NOT NULL
);


ALTER TABLE public.product_category_name_translation OWNER TO postgres;

--
-- TOC entry 225 (class 1259 OID 16860)
-- Name: products; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.products (
    product_id character varying(32) NOT NULL,
    product_category_name character varying(100),
    product_name_lenght integer,
    product_description_lenght integer,
    product_photos_qty integer,
    product_weight_g integer,
    product_length_cm integer,
    product_height_cm integer,
    product_width_cm integer,
    CONSTRAINT chk_product_dims_nonneg CHECK (((product_weight_g >= 0) AND (product_length_cm >= 0) AND (product_height_cm >= 0) AND (product_width_cm >= 0))),
    CONSTRAINT chk_product_meta_nonneg CHECK (((product_photos_qty >= 0) AND (product_name_lenght >= 0) AND (product_description_lenght >= 0)))
);


ALTER TABLE public.products OWNER TO postgres;

--
-- TOC entry 226 (class 1259 OID 16867)
-- Name: sellers; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.sellers (
    seller_id character varying(32) NOT NULL,
    seller_zip_code_prefix character(5) NOT NULL,
    seller_city character varying(64) NOT NULL,
    seller_state character(2) NOT NULL,
    CONSTRAINT chk_seller_state CHECK ((seller_state ~ '^[A-Z]{2}$'::text)),
    CONSTRAINT chk_seller_zip CHECK ((seller_zip_code_prefix ~ '^[0-9]{5}$'::text))
);


ALTER TABLE public.sellers OWNER TO postgres;

--
-- TOC entry 3723 (class 2606 OID 16825)
-- Name: customers customers_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.customers
    ADD CONSTRAINT customers_pkey PRIMARY KEY (customer_id);


--
-- TOC entry 3728 (class 2606 OID 17179)
-- Name: order_items order_items_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.order_items
    ADD CONSTRAINT order_items_pkey PRIMARY KEY (order_id, order_item_id);


--
-- TOC entry 3737 (class 2606 OID 17169)
-- Name: orders orders_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.orders
    ADD CONSTRAINT orders_pkey PRIMARY KEY (order_id);


--
-- TOC entry 3731 (class 2606 OID 17183)
-- Name: payments payments_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.payments
    ADD CONSTRAINT payments_pkey PRIMARY KEY (order_id, payment_sequential);


--
-- TOC entry 3744 (class 2606 OID 17186)
-- Name: product_category_name_translation product_category_name_translation_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.product_category_name_translation
    ADD CONSTRAINT product_category_name_translation_pkey PRIMARY KEY (product_category_name);


--
-- TOC entry 3740 (class 2606 OID 17172)
-- Name: products products_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.products
    ADD CONSTRAINT products_pkey PRIMARY KEY (product_id);


--
-- TOC entry 3742 (class 2606 OID 17175)
-- Name: sellers sellers_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.sellers
    ADD CONSTRAINT sellers_pkey PRIMARY KEY (seller_id);


--
-- TOC entry 3724 (class 1259 OID 17354)
-- Name: idx_customers_unique_id; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_customers_unique_id ON public.customers USING btree (customer_unique_id);


--
-- TOC entry 3725 (class 1259 OID 17352)
-- Name: idx_order_items_product_id; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_order_items_product_id ON public.order_items USING btree (product_id);


--
-- TOC entry 3726 (class 1259 OID 17353)
-- Name: idx_order_items_seller_id; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_order_items_seller_id ON public.order_items USING btree (seller_id);


--
-- TOC entry 3733 (class 1259 OID 17351)
-- Name: idx_orders_customer_id; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_orders_customer_id ON public.orders USING btree (customer_id);


--
-- TOC entry 3734 (class 1259 OID 17357)
-- Name: idx_orders_delivered; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_orders_delivered ON public.orders USING btree (order_id) INCLUDE (order_delivered_customer_date, order_estimated_delivery_date) WHERE (((order_status)::text = 'delivered'::text) AND (order_delivered_customer_date IS NOT NULL));


--
-- TOC entry 3735 (class 1259 OID 17355)
-- Name: idx_orders_purchase_ts; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_orders_purchase_ts ON public.orders USING btree (order_purchase_timestamp);


--
-- TOC entry 3729 (class 1259 OID 17358)
-- Name: idx_payments_order_value; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_payments_order_value ON public.payments USING btree (order_id, payment_value DESC, payment_sequential) INCLUDE (payment_type, payment_installments);


--
-- TOC entry 3738 (class 1259 OID 17359)
-- Name: idx_products_category; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_products_category ON public.products USING btree (product_category_name);


--
-- TOC entry 3732 (class 1259 OID 17356)
-- Name: idx_reviews_order_latest; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_reviews_order_latest ON public.order_reviews USING btree (order_id, review_creation_date DESC, review_answer_timestamp DESC) INCLUDE (review_score);


--
-- TOC entry 3745 (class 2606 OID 17192)
-- Name: order_items fk_items_order; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.order_items
    ADD CONSTRAINT fk_items_order FOREIGN KEY (order_id) REFERENCES public.orders(order_id);


--
-- TOC entry 3746 (class 2606 OID 17197)
-- Name: order_items fk_items_product; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.order_items
    ADD CONSTRAINT fk_items_product FOREIGN KEY (product_id) REFERENCES public.products(product_id);


--
-- TOC entry 3747 (class 2606 OID 17202)
-- Name: order_items fk_items_seller; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.order_items
    ADD CONSTRAINT fk_items_seller FOREIGN KEY (seller_id) REFERENCES public.sellers(seller_id);


--
-- TOC entry 3750 (class 2606 OID 17187)
-- Name: orders fk_orders_customer; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.orders
    ADD CONSTRAINT fk_orders_customer FOREIGN KEY (customer_id) REFERENCES public.customers(customer_id);


--
-- TOC entry 3748 (class 2606 OID 17212)
-- Name: payments fk_payments_order; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.payments
    ADD CONSTRAINT fk_payments_order FOREIGN KEY (order_id) REFERENCES public.orders(order_id);


--
-- TOC entry 3751 (class 2606 OID 17217)
-- Name: products fk_products_category; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.products
    ADD CONSTRAINT fk_products_category FOREIGN KEY (product_category_name) REFERENCES public.product_category_name_translation(product_category_name);


--
-- TOC entry 3749 (class 2606 OID 17207)
-- Name: order_reviews fk_reviews_order; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.order_reviews
    ADD CONSTRAINT fk_reviews_order FOREIGN KEY (order_id) REFERENCES public.orders(order_id);


-- Completed on 2026-11-17 11:03:51 MSK

--
-- PostgreSQL database dump complete
--

\unrestrict 5jnHZeUAlBtAj1qiNZOYA1QcAVkyOWev6ThGCS9btQjPFlPUeHx2TunI1waSa4B

