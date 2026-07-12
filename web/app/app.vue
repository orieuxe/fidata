<template>
  <v-app>
    <v-app-bar title="FIDE Ratings">
      <v-btn to="/" text="Top players" />
      <v-btn to="/active" text="Most active" />
    </v-app-bar>
    <v-main>
      <NuxtPage />
    </v-main>
  </v-app>
</template>
