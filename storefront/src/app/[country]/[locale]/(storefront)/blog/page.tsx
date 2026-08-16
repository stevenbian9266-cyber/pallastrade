import type { Metadata } from "next";
import Link from "next/link";
import { getTranslations } from "next-intl/server";
import { PostCard } from "@/components/blog/PostCard";
import { listPosts } from "@/lib/data/posts";
import { getStoreName } from "@/lib/store";

interface BlogPageProps {
  params: Promise<{
    country: string;
    locale: string;
  }>;
}

export async function generateMetadata({
  params,
}: BlogPageProps): Promise<Metadata> {
  const { locale } = await params;
  const storeName = getStoreName();
  const t = await getTranslations({
    locale: locale as Locale,
    namespace: "blog",
  });

  return {
    title: storeName ? `${t("title")} | ${storeName}` : t("title"),
    description: t("description"),
  };
}

export default async function BlogPage({ params }: BlogPageProps) {
  const { country, locale } = await params;
  const [posts, t] = await Promise.all([
    listPosts(),
    getTranslations({ locale: locale as Locale, namespace: "blog" }),
  ]);

  const basePath = `/${country}/${locale}`;

  return (
    <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-12">
      <div className="text-center mb-12">
        <h1 className="text-4xl font-bold text-gray-900 mb-4">{t("title")}</h1>
        <p className="text-lg text-gray-600 max-w-2xl mx-auto">
          {t("description")}
        </p>
      </div>

      {posts.length === 0 ? (
        <p className="text-center text-gray-500 py-16">{t("empty")}</p>
      ) : (
        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-8">
          {posts.map((post) => (
            <Link
              key={post.id}
              href={`${basePath}/blog/${post.slug}`}
              className="group"
            >
              <PostCard post={post} />
            </Link>
          ))}
        </div>
      )}
    </div>
  );
}
